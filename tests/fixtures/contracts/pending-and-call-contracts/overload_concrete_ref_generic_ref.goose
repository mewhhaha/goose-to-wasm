fn choose<T>(v: T&) { print("generic-reference"); }
fn choose(v: i64&) { print("reference"); }
fn main() { var a = 1; var b = 2; choose(if a < b { a } else { b }); }
