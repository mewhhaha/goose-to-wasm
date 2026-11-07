fn choose(v: i64) { print("value"); }
fn choose(v: i64&) { print("reference"); }
fn main() { var a = 1; choose(if true { a } else { 2 }); }
