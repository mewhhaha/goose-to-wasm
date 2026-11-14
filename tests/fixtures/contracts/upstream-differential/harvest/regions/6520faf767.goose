enum Choice { Empty, Data { value: i64 } }
var choice: Choice = Choice.Data { 1234605616436508552 };
var neighbor: i64[>..] = [987654321];
fn value(c: Choice.Empty) -> i64 { 0 }
fn value(c: Choice.Data) -> i64 { c.value }
export fn tick(n: i64) -> i64 { value(choice) + n }
fn main() {}