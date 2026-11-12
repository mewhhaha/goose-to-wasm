// A reference to an owner is a plain reference.
root struct S { n: i64 }
struct Link { s: S&<u32> }
fn main() {}
