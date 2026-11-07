fn both() -> i64, i64 { return 3, 4; }
fn fill(a: const i64&, b: i64&) { a, b = both(); }
fn main() { var a = 0; var b = 0; fill(a, b); }
