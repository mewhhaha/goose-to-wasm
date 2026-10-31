var calls=0;
recursive fn mark(n:i64)->i64{calls++;print("mark ",n);return n;}
fn main(){
 let z:varint[u8]=[mark(64);0];print("zero ",z.len," ",calls);
 let f:varint[u16]=[mark(-65);3];print(f," ",calls);
 let x:varint[u64]=[mark(-1),mark(8192),mark(-9223372036854775808),mark(9223372036854775807)];
 print(x," ",calls);
}
