enum Event { Empty, Big { values:i64[u32] } }
var neighbor:i64[>..] = [987654321];
fn value()->i64 { print(123); return 1; }
fn main() { let e:Event.. = Event.Big{[value();1000000]}; }