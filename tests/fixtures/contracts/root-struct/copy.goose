// An owner is never copied.
root struct S { a: i64[>..] }
fn main() { var s = S { .. }; let t = copy(s); }
