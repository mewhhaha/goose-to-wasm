struct Packet { id: i64, values: i64[] }
var neighbor: i64[>..] = [987654321];
fn value() -> i64 { print(123); return 1; }
var packet = Packet { 2, [value(); 1000000] };
fn main() {}