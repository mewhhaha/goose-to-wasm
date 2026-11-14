var neighbor:i64[>..]=[987654321];
recursive fn make()->varint[varint]{var a:varint[>..]=[7;128];return a;}
export fn tick(n:i64)->i64{let a=make();var total=0;for x in a{total+=x;}if a.len!=128 || total!=896{abort("bad ULEB result");}return n+1;}
fn main(){}