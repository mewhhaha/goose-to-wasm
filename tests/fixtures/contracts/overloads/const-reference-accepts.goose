// A read-only reference and a const value parameter take mutable arguments.
struct S { x: i64 }
fn g(v: const S&) { print(v.x); }
fn h(v: const u32[:]) { print(v.len); }
fn main() { var s = S { 1 }; g(s); var m: u32[:] = default<u32[:]>(); h(m); }
