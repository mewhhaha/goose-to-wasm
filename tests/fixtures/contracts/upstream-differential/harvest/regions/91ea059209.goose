var neighbor:i64[>..]=[987654321];
recursive fn make()->u8[varint]{var a:u8[>..]=[7;128];return a;}
export fn tick(n:i64)->i64{let a=make();if a.len!=128 || a[0]!=7 || a[127]!=7{abort("bad ULEB result");}return n+1;}
fn main(){}