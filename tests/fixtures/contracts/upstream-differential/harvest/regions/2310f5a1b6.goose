fn bench_input() -> i64 { return 5; }
var neighbor: i64[>..] = [987654321];
fn main() {
    var values: i64[>..] = [1];
    recursive fn replace() { values = [if bench_input() > 0 { return; } else { 2 }; 1000000]; }
    replace();
}