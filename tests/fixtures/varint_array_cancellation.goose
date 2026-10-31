recursive fn make<F>()->varint[u16]{return[1,F(),-65];}
recursive fn empty<F>()->varint[u16]{return[F();0];}
fn target(stop:bool)->i64 {let a=make(){if stop{return 77;}else{8192}};var s=0;for x in a{s+=x;}return s;}
fn zero(stop:bool)->i64 {let a=empty(){if stop{return 88;}else{9}};return a.len;}
recursive fn interrupted(stop:bool)->varint[u16],i64,varint[u16]{
 return[1,if stop{return[-65],9,[8192];}else{2}],3,[4];
}
fn main(){print(target(true)," ",target(false));print(zero(true)," ",zero(false));
 for b in [false,true]{let a,n,c=interrupted(b);print(a," ",n," ",c);}}

