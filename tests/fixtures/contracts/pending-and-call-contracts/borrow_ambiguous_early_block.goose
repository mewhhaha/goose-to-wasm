fn pick(x: i64&) -> i64 { x }
fn pick(x: i64) -> i64 { x }
fn main() { var a = 1; var b = 2; let c = a < b; print(pick(block { if c { break a; } b })); }
