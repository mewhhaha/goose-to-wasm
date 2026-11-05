struct Stack { n: i64, items: i64[>..<] }
struct Mid { k: i64, stack: Stack }
struct Deep { n: i64, mid: Mid }
fn grow(xs: i64[>..<]&) { xs.push(2); }
fn fill(d: Deep&) { grow(d.mid.stack.items); }
fn main() { var d = Deep { n: 0, mid: Mid { k: 0, stack: Stack { n: 0, items: [1] } } }; let r = &d.mid.stack.items; r.push(3); fill(d); print(d.mid.stack.items.len); }
