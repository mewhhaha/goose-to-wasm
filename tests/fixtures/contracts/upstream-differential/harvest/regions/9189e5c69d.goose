var neighbor:i64[>..]=[987654321];
struct R{tag:u8,word:u16,values:varint[varint]}
recursive fn make(n:i64)->R{if n==0{return R{1,7,[64;128]};}return make(n-1);}
export fn tick(n:i64)->i64{let a=make(20);var total=0;for x in a.values{total+=x;}
if a.word!=7 || a.values.len!=128 || total!=8192{abort("bad record tail");}return n+1;}
fn main(){}