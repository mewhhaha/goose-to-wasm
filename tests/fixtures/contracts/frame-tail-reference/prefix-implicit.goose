struct Stack { n: i64, items: i64[>..<] }
struct Named { name: u8[], stack: Stack }
fn grow(xs: i64[>..<]&) { xs.push(2); }
fn main() { var v = Named { name: "x", stack: Stack { n: 0, items: [1] } }; grow(v.stack.items); }
