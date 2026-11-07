fn pick(x: i64&) -> i64 { 1 }
fn pick<T>(x: T) -> i64 { 2 }
fn main() { var a = 7; print(pick(a)); }
