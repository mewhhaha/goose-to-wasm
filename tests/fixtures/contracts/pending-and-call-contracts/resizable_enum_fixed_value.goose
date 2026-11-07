enum Value { A { n: i64 }, B { items: i64[>..] } }
fn main() { var v: Value.. = Value.A { 7 }; match v { A a => print(a.n), B => print("B") } }
