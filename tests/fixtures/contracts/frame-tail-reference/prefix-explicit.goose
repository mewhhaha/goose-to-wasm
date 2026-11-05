struct Stack { n: i64, items: i64[>..<] }
struct Named { name: u8[], stack: Stack }
fn main() { var v = Named { name: "x", stack: Stack { n: 0, items: [1] } }; let r = &v.stack.items; r.push(2); }
