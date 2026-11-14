fn bench_input() -> i64 { return 5; }
fn grow(values: i64[>..], neighbor: i64[>..]) -> i64 {
    values.resize(bench_input(), 7); return neighbor[0];
}
fn main() { print(grow([1], [987654321])); }