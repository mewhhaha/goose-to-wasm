enum Inner { Empty, A { n:i64, items:i64[>..] } }
enum Outer { Empty, W { k:i64, inner:Inner.. } }
struct Wrap { id:i64, value:Outer.. }
fn make(n:i64)->Outer.. { Outer.W{n,Inner.A{n+1,[n+2,n+3]}} }
fn main(){ var a:Outer..=make(1); print(a); var w=Wrap{5,make(6)}; print(w); a=Outer.Empty; print(w); w.value=make(8); print(w); }
