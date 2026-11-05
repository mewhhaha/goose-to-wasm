fn pos(a: const i64[3]&) -> i64 { a.index_of(&a[1]) }
fn main() { var a: i64[3] = [1,2,3]; print(pos(a)); }
