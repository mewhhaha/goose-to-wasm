// Nor a mutable struct a reference to a const one.
struct S { x: i64 }
fn g(v: (const S)&) { print(v.x); }
fn main() { var s = S { 1 }; g(s); }
