fn choose<T>(v: T) { print("generic"); }
fn choose(v: i64&) { print("reference"); }
fn main() { var a = 1; var b = 2; choose(if a < b { a } else { b }); }
