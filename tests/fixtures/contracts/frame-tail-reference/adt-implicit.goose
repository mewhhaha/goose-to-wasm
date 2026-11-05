struct Stack { n: i64, items: i64[>..<] }
enum E { A { stack: Stack } }
fn grow(xs: i64[>..<]&) { xs.push(2); }
export fn bad(p: E.A&) { grow(p.stack.items); }
fn main() {}
