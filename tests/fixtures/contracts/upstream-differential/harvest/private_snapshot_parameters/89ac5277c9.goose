struct Pair { first:i64, second:i64 }
recursive fn bump(value:i64&) { value++; }
recursive fn exposed(p:Pair)->i64 { bump(p.first); return p.first+p.second; }
fn main() { let p=Pair { 1,2 }; print(exposed(p)," ",p.first); }
