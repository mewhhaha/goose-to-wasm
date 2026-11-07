fn write(v: i64&) { v = 9; }
fn main() { const a = 1; const b = 2; write(if true { a } else { b }); }
