struct Tail { label:i64, items:i64[>..] }
enum Value { Empty, A { n:i64, tail:Tail } }
struct Wrap { outer:i64, value:Value.. }
fn main() {
 var a:Value..=Value.A{7,Tail{8,[1,2,3]}}; print(a);
 var w=Wrap{9,Value.A{7,Tail{8,[1,2,3]}}}; print(w); a=Value.Empty; print(w); print(a);
 w.value=Value.A{10,Tail{11,[]}}; print(w);
 w.value=Value.Empty; print(w);
 w.value=Value.A{12,Tail{13,[4,5]}}; print(w);
}
