fn choose(v: i64&) { print("plain"); }
fn choose(v: i64&?) { print("optional"); }
fn main() { choose(null); }
