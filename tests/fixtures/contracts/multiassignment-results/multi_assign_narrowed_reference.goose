fn pair() -> i64, i64 { return 3, 4; }
fn fill(a: i64&?, b: i64&) { if a { a, b = pair(); } }
fn main() { var a = 0; var b = 0; fill(a, b); print(a, " ", b); }
