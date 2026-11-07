fn choose(v: i64) { print("value"); }
fn choose(v: i64&) { print("reference"); }
fn main() { choose(if true { 1 } else { 2 }); }
