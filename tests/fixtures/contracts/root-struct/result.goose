// A result returns a reference to an owner, never an owner.
root struct S { n: i64 }
fn f() -> S { S { 1 } }
fn main() {}
