fn make() -> i64[>..], i64 { return [1], 2; }
fn main() { let values, n = make(); print(values[n % values.len]); }
