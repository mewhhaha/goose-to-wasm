fn bump(x: i64&) { x += 1; }
fn main() { var a=1; var b=2; bump(match a { 1 => a, _ => b }); print(a," ",b); }
