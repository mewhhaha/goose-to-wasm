fn choose(v: i64) { print("value"); }
fn choose(v: i32&) { print("narrow-reference"); }
fn main() { var a: i64 = 1; var b: i64 = 2; choose(if a < b { a } else { b }); }
