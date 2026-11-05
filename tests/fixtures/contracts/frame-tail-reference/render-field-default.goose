struct Stack { n: i64, items: i64[>..<] }
struct Named { name: u8[], stack: Stack }
var g = Named { name: "x", stack: Stack { n: 0, items: [1] } };
struct B { n: i64 }
struct Hold { r: i64[>..<]& = g.stack.items }
fn format(out: u8[>..]&, v: B) { let h = Hold {}; h.r.push(2); out.append("B"); }
fn main() { print(B { n: 1 }); }
