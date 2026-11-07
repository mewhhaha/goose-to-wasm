enum Value { Empty, A { n:i64, items:i64[>..] } }
struct Wrap { id:i64, value:Value.. }
fn replace(v:Wrap&, n:i64){ v.value=Value.A{n,[n+1,n+2]}; }
fn main(){ var w=Wrap{9,Value.A{1,[2,3]}}; replace(w,4); print(w); w.id=10; replace(w,6); print(w); }
