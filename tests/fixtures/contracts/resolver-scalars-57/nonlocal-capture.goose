recursive fn target() -> i64 { var x: i64 = 1; var unrelated: i64 = 1; unrelated++; print(unrelated); recursive fn leave() { x += 4; print(x); return x + 37 from target; } leave(); return 0; }
fn main() { print(target()); }
