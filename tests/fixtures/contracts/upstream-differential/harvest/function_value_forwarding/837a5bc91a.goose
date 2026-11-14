
fn invoke<F>(a:i64[:],b:i64[:])->bool { F(a,b) }
fn forward<F>(a:i64[:],b:i64[:])->bool { invoke(a,b) { x,y => F(x,y) } }
fn run()->bool { let a=[1]; let b=[2]; forward(a[..],b[..]) { x,y => x.len<y.len } }
fn main() { print(run()); }
