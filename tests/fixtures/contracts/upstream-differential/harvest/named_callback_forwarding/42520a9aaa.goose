
fn invoke<F>(a:i64[:],b:i64[:]) { F(a,b) }
recursive fn terminal(a:i64[:],b:i64[:])->i64 { a[0]*100+b[0] }
recursive fn run() { let a=[1,10]; let b=[2,20]; print(invoke(a[..],b[..]) { x,y => terminal(x,y) }); }
fn main() { run(); }
