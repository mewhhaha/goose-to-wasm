struct Stack { n: i64, items: i64[>..<] }
struct Box<T> { tag: T, stack: Stack }
fn main() { var b = Box { tag: 7, stack: Stack { n: 0, items: [1] } }; let r = &b.stack.items; r.push(2); print(b.stack.items.len); }
