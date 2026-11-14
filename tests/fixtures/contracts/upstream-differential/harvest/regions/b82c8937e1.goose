var neighbor:i64[>..]=[987654321];
struct Text{value:i64,bytes:u8[2048]}
export fn tick(n:i64)->i64{print(Text{n,[65;2048]});return n+1;}
fn main(){}