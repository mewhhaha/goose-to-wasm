struct R {value:varint,pad 70000,after:u8}
var neighbor:i64[>..]=[987654321];
fn make<F>()->R {return R{F(),7};}
fn target(n:i64)->i64 {let r=make(){if n>=0 {return n+1;}else{0}};return r.value;}
export fn tick(n:i64)->i64 {target(n)}
fn main() {}