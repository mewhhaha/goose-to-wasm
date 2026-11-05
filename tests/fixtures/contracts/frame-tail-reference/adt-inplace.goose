struct Stack { n: i64, items: i64[>..<] }
enum E { A { stack: Stack } }
export fn mutate(p: E.A&) { p.stack.items.push(2); }
fn main() {}
