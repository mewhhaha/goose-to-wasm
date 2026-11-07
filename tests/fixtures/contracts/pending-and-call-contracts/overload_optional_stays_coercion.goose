fn choose(v: i64) { print("value"); }
fn choose(v: i64&?) { print("optional"); }
fn main() { var a = 1; var b = 2; choose(if a < b { a } else { b }); }
