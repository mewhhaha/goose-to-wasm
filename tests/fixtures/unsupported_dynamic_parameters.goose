extern fn bench_input() -> i64;
inline fn take(values: i64[>..]) -> i64 {
    for i in 100 { values.push(i); }
    return values[bench_input() % values.len];
}
fn main() { print(take([1, 2])); }
