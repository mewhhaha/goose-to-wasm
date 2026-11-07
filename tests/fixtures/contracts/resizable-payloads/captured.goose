enum Value { Empty, A { n:i64, items:i64[>..] } }
fn make(n:i64)->Value.. { Value.A{n,[n+1,n+2]} }
fn main(){ var a:Value..=make(1); var b:Value..=make(1); a=Value.Empty; print(b); b=make(4); a=make(4); b=Value.Empty; print(a); }
