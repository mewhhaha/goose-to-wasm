
struct Pair { first:i64, second:i64 }
fn invoke<F>(a:Pair,b:Pair) { F(a,b) }
var state=Pair { 1, 10 }; var observed:i64=0;
fn first()->Pair { state }
fn later()->Pair { state.first=99; return state; }
recursive fn terminal(a:Pair,b:Pair)->i64 { a.first*100+b.first }
recursive fn run() { print(invoke(first(),later()) { x,y => observed+=1; terminal(x,y) }," ",state.first); }
fn main() { run(); }
