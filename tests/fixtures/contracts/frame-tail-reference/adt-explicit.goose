struct Stack { n: i64, items: i64[>..<] }
enum E { A { stack: Stack } }
export fn bad(p: E.A&) { let r = &p.stack.items; r.push(2); }
fn main() {}
