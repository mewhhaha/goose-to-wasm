enum Event { Data { id: i64, values: i64[] } }
var neighbor: i64[>..] = [987654321];
fn value(n: i64) -> i64 { print(n); return 1; }
var p = Event.Data { value(123), [value(456); 1000000] };
fn main() {}