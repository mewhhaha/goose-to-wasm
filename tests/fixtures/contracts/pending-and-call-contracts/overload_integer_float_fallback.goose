fn choose(v: i64&) { print("reference"); }
fn choose(v: f64) { print("float"); }
fn main() { var a = 1; choose(a); choose(2); }
