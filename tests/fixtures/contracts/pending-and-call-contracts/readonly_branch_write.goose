fn write(v: i64&) { v = 9; }
fn main() { let a = 1; let b = 2; write(if true { a } else { b }); }
