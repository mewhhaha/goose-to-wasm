struct Stack { n: i64, items: i64[>..<] }
struct Linked { p: i64&, stack: Stack }
fn main() { var x = 0; var v = Linked { p: x, stack: Stack { n: 0, items: [1] } }; let r = &v.stack.items; r.push(2); print(v.stack.items.len); }
