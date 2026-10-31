recursive fn at(xs:const varint[:],index:i64)->i64{for x,i in xs{if i==index{return x;}}abort("missing");}
recursive fn make(n:i64)->varint[varint]{var a:varint[>..]=[];for i in 0..n{a.push((i%256) as u8);}return a;}
inline fn imake(n:i64)->varint[varint]{var a:varint[>..]=[];for i in 0..n{a.push((i%256) as u8);}return a;}
fn main(){for n in[0,1,127,128,16383,16384]{let a=make(n);let b=imake(n);print(a.len," ",b.len);if n>0{print(at(a,n-1) as i64," ",at(b,n-1) as i64);}}}
