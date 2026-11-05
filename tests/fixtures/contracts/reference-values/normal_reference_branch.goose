fn bump(x: i64&) { x += 1; }
fn main() { var a = 1; var b = 2; let c = a < b; bump(if c { a } else { b }); print(a,b); }
