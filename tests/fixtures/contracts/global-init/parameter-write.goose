var A: i64 = f(); var B: i64 = 3;
fn set(out: i64&) { out = 7; }
fn f() -> i64 { set(B); 1 }
fn main() { print(A, B); }
