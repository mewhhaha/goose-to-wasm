var neighbor: i64[>..] = [987654321];
fn fill(value: i64) -> i64 { return [value + 1] from target; }
fn target(value: i64) -> i64[>..] { return [fill(value); 4294967296]; }
export fn tick(n: i64) -> i64 { var result = target(n); result[0] }
fn main() {}