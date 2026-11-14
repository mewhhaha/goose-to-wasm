var encoded:varint[>..]=[11];
var xs:u32[>..]=[11;64];
recursive fn work(end:i64,stride:i64)->i64 {
     var cur=1;
    while cur<end { xs[cur]=4045620583; cur+=stride; }
    var count:i64=0;
    for value,i in xs {
        if i%3==1 { if value!=4045620583 { return -1; } count++; }
        else { if value!=11 { return -2; } }
    }
    return count;
}
fn main() { for value in encoded { if value!=11 { abort("wrong encoded value"); } } print(work(64,3)); }
