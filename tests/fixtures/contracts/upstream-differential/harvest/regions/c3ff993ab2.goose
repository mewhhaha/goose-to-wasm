var neighbor:i64[>..]=[987654321];
recursive fn make<F>()->varint[u16]{return[1,F(),-65];}
fn target(n:i64)->i64{let rows=make(){if n>=0{return n+1;}else{8192}};return rows.len;}
export fn tick(n:i64)->i64{target(n)}
fn main(){}