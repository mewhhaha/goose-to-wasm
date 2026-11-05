struct Stack { n: i64, items: i64[>..<] }
fn main() { var s = Stack { n: 0, items: [1] }; let r = &s.items; r.push(2); print(s.items.len); }
