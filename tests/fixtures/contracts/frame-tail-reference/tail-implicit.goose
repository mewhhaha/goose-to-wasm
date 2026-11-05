struct Stack { n: i64, items: i64[>..<] }
fn grow(xs: i64[>..<]&) { xs.push(2); }
fn main() { var s = Stack { n: 0, items: [1] }; grow(s.items); print(s.items.len); }
