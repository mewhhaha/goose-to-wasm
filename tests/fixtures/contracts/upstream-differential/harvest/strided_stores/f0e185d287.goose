var xs:i64[64]=[11;64];
recursive fn work(end:i64,stride:i64)->i64 {
     var cur=1;
    while cur<end { xs[cur]=-6510615555426900571; cur+=stride; }
    var count:i64=0;
    for value,i in xs {
        if i%3==1 { if value!=-6510615555426900571 { return -1; } count++; }
        else { if value!=11 { return -2; } }
    }
    return count;
}
fn main() { print(work(64,3)); }
