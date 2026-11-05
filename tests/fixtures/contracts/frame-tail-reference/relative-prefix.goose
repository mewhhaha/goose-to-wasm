struct Stack { n: i64, items: i64[>..<] }
struct Rel { link: i64&<u32>?, stack: Stack }
fn main() { var v = Rel { link: null, stack: Stack { n: 0, items: [1] } }; let r = &v.stack.items; r.push(2); }
