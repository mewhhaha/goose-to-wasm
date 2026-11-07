struct Item { n: i64 }
struct Box { inner: Item }
const original = Box { inner: Item { n: 1 } };
fn main() { var copied = original.inner; copied.n = 2; print(copied.n, " ", original.inner.n); }
