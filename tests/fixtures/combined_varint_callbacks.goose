recursive fn at(xs:const varint[:],index:i64)->i64{for x,i in xs{if i==index{return x;}}abort("missing");}
fn invoke<F>(n:i64)->varint[varint]{return F(n);}recursive fn make<F>()->varint[varint]{return[F();128];}
fn target(flag:bool)->i64{let a=make(){if flag{return 7;}else{8}};return a.len;}
fn main(){let a=invoke(9){n=>let xs:varint[varint]=[n as u8;128];copy(xs)};print(a.len," ",at(a,127) as i64);print(target(true)," ",target(false));}
