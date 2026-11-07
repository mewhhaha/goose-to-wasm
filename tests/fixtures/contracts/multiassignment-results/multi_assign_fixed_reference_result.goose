fn pair(a: i64&) -> i64&, i64 { return a, 4; }
fn main() { var a = 3; var b = 0; var c = 0; b, c = pair(a); a = 9; print(b, " ", c, " ", a); }
