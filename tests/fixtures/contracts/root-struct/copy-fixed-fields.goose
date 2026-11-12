// Not even when its fields are all fixed-size.
root struct S { n: i64 }
fn main() { var s = S { 1 }; var t: S = s; print(t.n); }
