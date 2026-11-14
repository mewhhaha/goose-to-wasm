var values:i64[8]=[11,22,33,44,55,66,77,88];
export fn run(count:i64,offset:i64) {
    var xs=values[..]; var j=7;
    while j>7-count && xs[j-1]>0 { xs[j-offset]=xs[j-1]; j--; }
}
export fn read(i:i64)->i64 { values[i] }
fn main() {}
