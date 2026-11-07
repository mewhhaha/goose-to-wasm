struct Item { n: i64 }
struct Box { const inner: Item }
const original = Box { inner: Item { n: 1 } };
fn main() { var copied = original; copied.inner.n = 2; }
