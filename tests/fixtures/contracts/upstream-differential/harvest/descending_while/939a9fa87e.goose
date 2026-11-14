recursive fn visit(mode:i64)->i64 {
    var values:i64[8]=[11,22,33,44,55,66,77,88]; let xs=values[..]; var j=7;
    while j>0 && xs[j-1]>0 {
        xs[j]=xs[j-1];
        if mode==0 && j==5 { break; }
        if mode==1 && j==5 { xs[j-1]=0; continue; }
        if mode==2 && j==5 { return j; }
        j--;
    }
    return j;
}
recursive fn observed(xs:i64[:],j:i64&)->i64 { j-=1; return xs[j]; }
recursive fn mutating()->i64 {
    var values:i64[8]=[11,22,33,44,55,66,77,88]; let xs=values[..]; var j=7;
    while j>0 && observed(xs,j)>0 { xs[j+1]=xs[j]; j--; }
    return j;
}
fn main() { print(visit(0)," ",visit(1)," ",visit(2)," ",visit(3)," ",mutating()); }
