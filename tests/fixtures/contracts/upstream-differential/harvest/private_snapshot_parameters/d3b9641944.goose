struct Pair { first:i64, second:i64 }
recursive fn descend(p:Pair,n:i64)->i64 {
    if n==0 { return p.first; }
    var local=p; local.first+=n;
    let result=descend(local,n-1); return result+p.first;
}
recursive fn mutate(var p:Pair)->i64 { p.first+=10; return p.first+p.second; }
recursive fn isolated(var a:Pair,var b:Pair)->i64 { a.first=9; return a.first*100+b.first; }
fn main() {
    let original=Pair { 1,2 };
    print(descend(original,3)," ",mutate(original)," ",descend(original,0)," ",original.first);
    print(isolated(original,original)," ",original.first);
}
