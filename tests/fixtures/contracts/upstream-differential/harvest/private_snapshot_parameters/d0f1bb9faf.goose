struct Pair { first:i64, second:i64 }
var source=Pair { 1,2 };
export fn change() { source.first=90; }
recursive fn hold(p:Pair)->i64 { print(p.first); return p.first; }
fn main() { print(hold(source)," ",source.first); }
