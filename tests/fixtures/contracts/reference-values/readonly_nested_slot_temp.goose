struct H { s: u8[:] }
struct W { h: H }
var g: u8[>..] = [];
fn mk() -> W { W { h: H { s: g[0..2] } } }
fn adv(p: u8[:]&) { p = p[1..]; }
fn main() { g.append("abc"); adv(mk().h.s); print(g); }
