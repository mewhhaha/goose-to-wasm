var saved:i32[:]; var backing:i32[8]=[11,22,33,44,55,66,77,88];
export fn run(start:i64,key:i32)->i64 {
    let xs=saved; var j=start;
    while j>0 && xs[j-1]>key { xs[j]=xs[j-1]; j--; }
    return j;
}
fn main() { saved=backing[..]; }
