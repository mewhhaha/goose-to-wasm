struct Stack { n: i64, items: i64[>..<] }
struct Named { name: u8[], stack: Stack }
fn get(v: Named&) -> i64[>..<]& { return v.stack.items; }
fn main() { var v = Named { name: "x", stack: Stack { n: 0, items: [1] } }; let r = get(v); r.push(2); }
