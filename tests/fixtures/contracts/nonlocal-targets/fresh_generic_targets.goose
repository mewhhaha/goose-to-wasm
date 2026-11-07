fn finish() { return 7 from target; }
fn relay() { finish(); }
fn target<T>(x: T) -> T { relay(); return x; }
fn main() { let a: i64 = 1; let b: i32 = 2; print(target(a), target(b)); }
