struct Stack { n: i64, items: i64[>..<] }
fn grow(s: Stack&) { s.items.push(2); }
fn main() { var s = Stack { n: 0, items: [1] }; grow(s); let r = &s; r.items.push(3); print(s.items.len); }
