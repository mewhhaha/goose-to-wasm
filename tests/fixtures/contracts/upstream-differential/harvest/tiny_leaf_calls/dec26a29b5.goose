 fn write(xs:i64[:],index:i64,value:i64) { var owned:i64[>..]=[value]; xs[index]=owned[0]; }
recursive fn drive() { var xs=[1,2]; write(xs[..],0,7); print(xs); }
fn main() { drive(); }
