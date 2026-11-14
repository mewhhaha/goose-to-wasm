 fn write(xs:i64[:],index:i64,value:i64) { for i in 1 { xs[index]=value; } }
recursive fn drive() { var xs=[1,2]; write(xs[..],0,7); print(xs); }
fn main() { drive(); }
