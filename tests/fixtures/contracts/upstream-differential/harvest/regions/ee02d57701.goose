struct Frame { id: i64, values: i64[>..] }
var neighbor: i64[>..] = [987654321];
fn fill(value: i64) -> i64 { return Frame { value + 1, [value + 2] } from target; }
fn target(value: i64) -> Frame { return Frame { 9, [fill(value); 4294967296] }; }
export fn tick(n: i64) -> i64 { var result = target(n); result.id }
fn main() {}