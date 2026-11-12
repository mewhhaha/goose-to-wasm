// Not even by another root owner.
root struct Inner { items: i64[>..] }
root struct Outer { inner: Inner }
fn main() {}
