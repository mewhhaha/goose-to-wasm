enum Event { Small { id:i64 }, Big { values:i64[8192] } }
var neighbor:i64[>..] = [987654321];
fn value()->i64 { print(123); return 1; }
fn main() { let e:Event.. = Event.Small{value()}; }