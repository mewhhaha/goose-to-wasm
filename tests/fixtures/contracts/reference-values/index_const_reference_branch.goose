fn pos(a: const i64[3]&, c: bool) -> i64 { a.index_of(if c { &a[1] } else { &a[0] }) }
fn main() { var a: i64[3] = [1,2,3]; print(pos(a,true)); }
