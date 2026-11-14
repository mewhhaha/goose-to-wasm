recursive fn make<F>()->u8[varint]{return[F();4294967296];}
recursive fn target(flag:bool)->i64{let a=make(){if flag{return 7;}else{8}};return a.len;}
fn main(){print(target(true));}