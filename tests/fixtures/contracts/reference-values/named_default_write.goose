fn zero(s: i64[:]) { s[0] = 0; }
fn main() { var a = default<i64[3]>(); zero(a); print(a); }
