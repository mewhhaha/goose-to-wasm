fn choose(v: i64) { print("value"); }
fn choose<T>(v: T&) { print("generic-reference"); }
fn main() { var a = 1; var b = 2; choose(if a < b { a } else { b }); }
