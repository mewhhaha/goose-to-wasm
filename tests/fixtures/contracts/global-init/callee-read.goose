var A: i64 = relay(); var B: i64 = 3;
fn read() -> i64 { B }
fn relay() -> i64 { read() }
fn main() { print(A, B); }
