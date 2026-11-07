fn set(x: i64&) { x = 9; }
fn main() { var a = 1; var b = 2; let c = a < b; set(if c { a } else { b }); set(loop { break b; }); print(a, " ", b); }
