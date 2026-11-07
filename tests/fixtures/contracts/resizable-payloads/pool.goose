var pool:i64[>..]=[];
enum Value { Empty, A { n:i64, p:i64&<u32 in pool>, items:i64[>..] } }
fn make()->Value.. { Value.A{3,pool[0],[4,5]} }
fn main(){ pool.push(9); var a:Value..=make(); print(a); pool[0]=10; print(a); a=Value.Empty; print(a); a=make(); print(a); }
