var saved:i64[:]; var secondary:i64[:];
var backing:i64[8]=[11,22,33,44,55,66,77,88];
var other:i64[8]=[201,202,203,204,205,206,207,208];
export fn run(start:i64,key:i64)->i64 {
    let xs=saved; let dst=secondary; var j=start;
    while j>0 && xs[j-1]>key { xs[j]=xs[j-1]; j--; }
    return j;
}
fn main() { saved=backing[..]; secondary=other[..]; }
