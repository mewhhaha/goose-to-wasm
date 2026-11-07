enum Value { Empty, A { n:i64, items:i64[>..<] } }
fn make(n:i64)->Value.. {
 if n<0 { return Value.Empty; }
 if n==0 { return Value.A{6,[]}; }
 var out:Value..=Value.A{n,[n,n+1]}; out
}
fn select(n:i64)->Value.. { if n>1 { make(n) } else { make(0) } }
fn main(){ var a:Value..=make(2); print(a); a=make(-1); print(a); a=select(2); print(a); a=select(1); print(a); }
