struct R {first:i64,pad 70000,second:i64,values:u8[u8]}
var neighbor:i64[>..]=[987654321];
fn value(n:i64)->i64 {print(n);return n;}
fn main() {let r=R{value(123),value(456),[]};}