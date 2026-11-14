recursive fn identity(n:i64)->i64 { return n; } fn write(xs:i64[:],index:i64,value:i64) { xs[index]=identity(value); }
recursive fn drive() { var xs=[1,2]; write(xs[..],0,7); print(xs); }
fn main() { drive(); }
