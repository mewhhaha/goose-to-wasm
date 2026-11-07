fn pair(a: i64&) -> i64&, i64 { return a, 4; }
fn change(a: i64&) -> i64 { a = 9; 0 }
fn main() { var a = 3; var xs = [0]; var out = 0; xs[change(a)], out = pair(a); print(xs, " ", out, " ", a); }
