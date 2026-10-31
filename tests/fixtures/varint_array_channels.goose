enum Choice{A,B}
recursive fn make(n:i64)->varint[u16]{return[n,-n,8192];}
inline fn inline_make(n:i64)->varint[u16]{return[n,64,-65];}
fn invoke<F>(n:i64)->varint[u16]{return F(n);}
recursive fn copied(xs:varint[u16])->varint[u16]{return copy(xs);}
recursive fn selected(c:Choice.A,n:i64)->varint[u16]{print("A");return[n,64];}
recursive fn selected(c:Choice.B,n:i64)->varint[u16]{print("B");return[-n,-65];}
recursive fn pair(n:i64)->varint[u8],i64,varint[u16]{return[n,64],n+1,[-n,-65];}
recursive fn relay(n:i64)->varint[u8],i64,varint[u16]{return pair(n);}
fn main(){
 print(make(7)," ",inline_make(8));
 print(invoke(9){x=>let xs:varint[u16]=[x,-x,8192];copy(xs)});
 let a=make(10);let b=copied(copy(a));print(a," ",b);
 for flag in [false,true]{let c:Choice=if flag{Choice.A}else{Choice.B};print(selected(c,11));}
 let x,n,y=relay(12);print(x," ",n," ",y);
}
