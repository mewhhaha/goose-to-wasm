enum Choice{A,B}
recursive fn make(n:i64)->varint[varint]{return[n,-n,8192];}
inline fn inline_make(n:i64)->varint[varint]{return[n,64,-65];}
fn invoke<F>(n:i64)->varint[varint]{return F(n);}
recursive fn copied(xs:varint[varint])->varint[varint]{return copy(xs);}
recursive fn selected(c:Choice.A,n:i64)->varint[varint]{print("A");return[n,64];}
recursive fn selected(c:Choice.B,n:i64)->varint[varint]{print("B");return[-n,-65];}
recursive fn pair(n:i64)->varint[varint],i64,varint[varint]{return[n,64],n+1,[-n,-65];}
recursive fn relay(n:i64)->varint[varint],i64,varint[varint]{return pair(n);}
fn main(){
 print(make(7)," ",inline_make(8));
 print(invoke(9){x=>let xs:varint[varint]=[x,-x,8192];copy(xs)});
 let a=make(10);let b=copied(copy(a));print(a," ",b);
 for flag in [false,true]{let c:Choice=if flag{Choice.A}else{Choice.B};print(selected(c,11));}
 let x,n,y=relay(12);print(x," ",n," ",y);
}
