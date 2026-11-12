// A field read, unlike an index, reads the struct value.
struct S { x: i64, y: i64 }
fn main() {
    var s: S;
    s.x = 1;
    print(s.x);
}
