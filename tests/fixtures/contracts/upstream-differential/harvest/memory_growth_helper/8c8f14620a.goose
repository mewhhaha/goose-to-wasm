var observed:i64=0;
export fn read()->i64 { observed }
export fn peek()->i64 { observed+1 }
recursive fn attempt(xs:u8[:])->i64 { observed=7; print(xs); return observed; }
fn main() { var empty:u8[0]; attempt(empty[..]); observed=0; }
