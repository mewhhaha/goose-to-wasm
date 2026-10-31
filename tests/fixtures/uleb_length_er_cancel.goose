recursive fn make<F>()->u8[u16]{return[F();128];}
recursive fn target(flag:bool)->i64{let a:u8[varint]=make(){if flag{return 7;}else{8}};return a.len;}
fn main(){print(target(true)," ",target(false));}
