fn invoke<F>(x: i64&, y: i64&) { F(if true { x } else { y }); }
fn main() { var a = 1; var b = 2; invoke(a, b) { v => a = 9; print(v, " ", a); }; }
