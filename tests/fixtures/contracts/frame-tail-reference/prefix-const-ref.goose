struct Stack { n: i64, items: i64[>..<] }
struct Named { name: u8[], stack: Stack }
fn read(xs: const i64[>..<]&) { print(xs.len); }
fn main() { var v = Named { name: "x", stack: Stack { n: 0, items: [1] } }; read(v.stack.items); }
