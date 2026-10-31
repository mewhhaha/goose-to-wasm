recursive fn make(n:i64)->u8[varint]{var a:u8[>..]=[];for i in 0..n{a.push((i%256) as u8);}return a;}
inline fn imake(n:i64)->u8[varint]{var a:u8[>..]=[];for i in 0..n{a.push((i%256) as u8);}return a;}
fn main(){for n in[0,1,127,128,16383,16384]{let a=make(n);let b=imake(n);print(a.len," ",b.len);if n>0{print(a[n-1] as i64," ",b[n-1] as i64);}}}
