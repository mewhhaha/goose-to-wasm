enum Value { A { items: i64[>..] } }
struct Standalone { items: i64[>..] }
fn main() {
    var v: Value.. = Value.A { items: [1, 2] };
    match v { A => print("tag") }
    var s = Standalone { items: [3] };
    s.items.push(4);
    print(s.items.len);
}
