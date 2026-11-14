
struct Pair { first:i64, second:i64 }
fn invoke<F>(a:Pair&,b:Pair&) { F(a,b) }
recursive fn terminal(a:Pair&,b:Pair&)->i64 { a.first*100+b.first }
recursive fn run() { var a=Pair { 1,10 }; var b=Pair { 2,20 }; print(invoke(a,b) { x,y => terminal(x,y) }); }
fn main() { run(); }
