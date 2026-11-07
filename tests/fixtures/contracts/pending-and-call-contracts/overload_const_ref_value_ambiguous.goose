fn choose(v: i64) { print("value"); }
fn choose(v: const i64&) { print("reference"); }
fn main() { var a = 1; let r: const i64& = a; choose(r); }
