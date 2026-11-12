// A nonfixed whole variable binds T by reference, and variants<T> then has
// no ADT to reflect on.
enum Shape { dot, line { points: i64[>..] }, empty }
fn shapeName<T>(value: T) -> i64 {
    match value { const for <N,V> in variants<T> { V => { print(N); return 1; }, } }
}
fn main() {
    var s: Shape.. = Shape.line { [1, 2] };
    print(shapeName(s));
}
