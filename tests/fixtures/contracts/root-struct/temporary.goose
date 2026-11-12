// An owner is constructed directly at its declaration.
root struct S { a: i64[>..] }
fn main() { var s = if true { S { .. } } else { S { .. } }; }
