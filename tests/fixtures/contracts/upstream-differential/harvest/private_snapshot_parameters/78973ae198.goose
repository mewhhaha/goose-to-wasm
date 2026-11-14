struct Pair { first:i64, second:i64 }
var source=Pair { 1,2 };
fn first()->Pair { source }
fn second()->Pair { source.first=99; return source; }
recursive fn receive(a:Pair,b:Pair,n:i64)->i64 { a.first*100+b.first*10+n }
fn invoke<F>(a:Pair,b:Pair,n:i64) { F(a,b,n) }
fn main() { print(invoke(first(),second(),7) { a,b,n=>receive(a,b,n) }," ",source.first); }
