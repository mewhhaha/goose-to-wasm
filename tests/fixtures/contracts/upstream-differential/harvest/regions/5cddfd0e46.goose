struct R {value:varint,pad 70000,after:u8}
var neighbor:i64[>..]=[987654321];
fn value(n:i64)->i64 {print(n);return n;}
fn main() {let r=R{value(11),value(22) as u8};}