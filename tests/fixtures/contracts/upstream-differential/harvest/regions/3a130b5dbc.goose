struct R{pad 0,value:varint}
var neighbor:i64[>..]=[987654321];
fn value()->i64{print(77);return 9223372036854775807;}
fn main(){let r=R{value()};print(r.value);}