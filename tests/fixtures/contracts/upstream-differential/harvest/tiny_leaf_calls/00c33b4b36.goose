 fn write(xs:i64[:],index:i64,value:i64) { recursive fn current()->i64 { return value; } xs[index]=current(); }
recursive fn drive() { var xs=[1,2]; write(xs[..],0,7); print(xs); }
fn main() { drive(); }
