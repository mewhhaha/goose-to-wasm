struct Pair { first:i64, second:i64 }
recursive fn identity(p:Pair)->Pair { p }
fn main() { let p=identity(Pair { 3,4 }); print(p.first+p.second); }
