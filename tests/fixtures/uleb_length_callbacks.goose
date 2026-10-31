fn invoke<F>(n:i64)->u8[varint]{return F(n);}recursive fn make<F>()->u8[varint]{return[F();128];}
fn target(flag:bool)->i64{let a=make(){if flag{return 7;}else{8}};return a.len;}
fn main(){let a=invoke(9){n=>let xs:u8[varint]=[n as u8;128];copy(xs)};print(a.len," ",a[127] as i64);print(target(true)," ",target(false));}
