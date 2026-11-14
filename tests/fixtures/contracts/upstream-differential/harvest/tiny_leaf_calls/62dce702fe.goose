 fn write(xs:i64[:],index:i64,value:i64) { let alias:i64& = index; xs[alias]=value; }
recursive fn drive() { var xs=[1,2]; write(xs[..],0,7); print(xs); }
fn main() { drive(); }
