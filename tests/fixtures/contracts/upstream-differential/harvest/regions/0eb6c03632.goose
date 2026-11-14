var neighbor: i64[>..] = [987654321];
fn value() -> i64 { print(123); return 1; }
fn main() { var values: i64[>..] = [value(); 1000000]; }